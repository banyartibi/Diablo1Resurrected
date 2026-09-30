#include <cstring>
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <memory>
#include <filesystem>
#include <SDL.h>
#include <png.h>

#include "engine/point.hpp"
#include "engine/surface.hpp"
#include "engine/render/dun_render.hpp"

namespace fs = std::filesystem;
using namespace devilution;

namespace devilution {
std::unique_ptr<byte[]> pDungeonCels;
std::array<std::array<uint8_t, 256>, 16> LightTables;
uint8_t paletteTransparencyLookup[256][256];
void app_fatal(std::string_view msg) {
	std::cerr << "FATAL: " << msg << std::endl;
	std::exit(1);
}
void assert_fail(int line, const char *file, const char *expr) {
	std::cerr << "ASSERT: " << expr << " at " << file << ":" << line << std::endl;
	std::abort();
}
} // namespace devilution

struct ColorRGBA {
	uint8_t r, g, b, a;
};

bool SavePNG(const std::string &filename, int width, int height, const std::vector<ColorRGBA> &pixels) {
	FILE *fp = fopen(filename.c_str(), "wb");
	if (!fp) return false;

	png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
	if (!png) { fclose(fp); return false; }

	png_infop info = png_create_info_struct(png);
	if (!info) {
		png_destroy_write_struct(&png, nullptr);
		fclose(fp);
		return false;
	}

	if (setjmp(png_jmpbuf(png))) {
		png_destroy_write_struct(&png, &info);
		fclose(fp);
		return false;
	}

	png_init_io(png, fp);
	png_set_IHDR(
		png, info, width, height, 8,
		PNG_COLOR_TYPE_RGBA, PNG_INTERLACE_NONE,
		PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT
	);
	png_write_info(png, info);

	std::vector<const uint8_t*> row_pointers(height);
	for (int y = 0; y < height; ++y) {
		row_pointers[y] = reinterpret_cast<const uint8_t*>(&pixels[y * width]);
	}

	png_write_image(png, const_cast<png_bytepp>(row_pointers.data()));
	png_write_end(png, nullptr);
	png_destroy_write_struct(&png, &info);
	fclose(fp);
	return true;
}

std::vector<ColorRGBA> LoadPalette(const std::string &pal_path) {
	std::vector<ColorRGBA> palette(256);
	std::ifstream f(pal_path, std::ios::binary);
	if (!f) {
		std::cerr << "Cannot open palette: " << pal_path << std::endl;
		return palette;
	}
	for (int i = 0; i < 256; ++i) {
		uint8_t r = 0, g = 0, b = 0;
		f.read(reinterpret_cast<char*>(&r), 1);
		f.read(reinterpret_cast<char*>(&g), 1);
		f.read(reinterpret_cast<char*>(&b), 1);
		palette[i] = { r, g, b, 255 };
	}
	palette[0] = { 0, 0, 0, 0 }; // Transparent
	return palette;
}

struct MICROS {
	uint16_t mt[16];
};

int main(int argc, char **argv) {
	if (argc < 5) {
		std::cout << "Usage: " << argv[0] << " <min_file> <cel_file> <pal_file> <out_dir> [theme: town|cathedral|catacombs|caves|hell]" << std::endl;
		return 1;
	}

	std::string min_path = argv[1];
	std::string cel_path = argv[2];
	std::string pal_path = argv[3];
	std::string out_dir = argv[4];
	std::string theme = (argc > 5) ? argv[5] : "cathedral";

	size_t blocks = 10;
	uint_fast8_t numMicros = 10;

	if (theme == "town" || min_path.find("town") != std::string::npos) {
		blocks = 16;
		numMicros = 16;
		std::cout << "[Exporter] Configured for Town (blocks=16, micros=16)" << std::endl;
	} else if (theme == "hell" || min_path.find("l4") != std::string::npos) {
		blocks = 16;
		numMicros = 12;
		std::cout << "[Exporter] Configured for Hell (blocks=16, micros=12)" << std::endl;
	} else {
		blocks = 10;
		numMicros = 10;
		std::cout << "[Exporter] Configured for Standard Dungeon (blocks=10, micros=10)" << std::endl;
	}

	std::cout << "[Exporter] Loading Palette: " << pal_path << std::endl;
	auto pal = LoadPalette(pal_path);

	// Initialize identity LightTable
	for (int i = 0; i < 256; ++i) {
		LightTables[0][i] = static_cast<uint8_t>(i);
	}

	std::cout << "[Exporter] Loading CEL: " << cel_path << std::endl;
	std::ifstream f_cel(cel_path, std::ios::binary | std::ios::ate);
	if (!f_cel) {
		std::cerr << "Failed to open CEL file: " << cel_path << std::endl;
		return 1;
	}
	size_t cel_size = f_cel.tellg();
	f_cel.seekg(0, std::ios::beg);
	pDungeonCels = std::unique_ptr<byte[]>(new byte[cel_size]);
	f_cel.read(reinterpret_cast<char*>(pDungeonCels.get()), cel_size);

	std::cout << "[Exporter] Loading MIN: " << min_path << std::endl;
	std::ifstream f_min(min_path, std::ios::binary | std::ios::ate);
	if (!f_min) {
		std::cerr << "Failed to open MIN file: " << min_path << std::endl;
		return 1;
	}
	size_t min_size = f_min.tellg();
	f_min.seekg(0, std::ios::beg);
	std::vector<uint16_t> levelPieces(min_size / 2);
	f_min.read(reinterpret_cast<char*>(levelPieces.data()), min_size);

	size_t numPieces = levelPieces.size() / blocks;
	std::vector<MICROS> dPieceMicros(numPieces);
	for (size_t i = 0; i < numPieces; i++) {
		uint16_t *pieces = &levelPieces[blocks * i];
		for (size_t block = 0; block < blocks; block++) {
			dPieceMicros[i].mt[block] = SDL_SwapLE16(pieces[blocks - 2 + (block & 1) - (block & 0xE)]);
		}
	}

	fs::create_directories(out_dir);

	std::cout << "[Exporter] Exporting " << numPieces << " dungeon pieces to " << out_dir << "..." << std::endl;
	int exported_count = 0;

	for (size_t pieceId = 0; pieceId < numPieces; ++pieceId) {
		const MICROS &micros = dPieceMicros[pieceId];
		int maxRow = -1;
		for (int i = 0; i < numMicros; i += 2) {
			if (LevelCelBlock(micros.mt[i]).hasValue() || (i + 1 < numMicros && LevelCelBlock(micros.mt[i + 1]).hasValue())) {
				maxRow = i / 2;
			}
		}
		if (maxRow < 0) continue;

		int numRows = maxRow + 1;
		int w = 64;
		int h = numRows * 32;

		SDL_Surface *sdl_surf = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
		if (!sdl_surf) continue;
		Surface surface(sdl_surf);
		std::memset(surface.begin(), 0, surface.pitch() * surface.h());

		const uint8_t *tbl = LightTables[0].data();
		Point renderPos { 0, h - 1 };

		for (int r = 0; r < numRows; ++r) {
			int i = r * 2;
			LevelCelBlock leftBlock { micros.mt[i] };
			if (leftBlock.hasValue()) {
				RenderTile(surface, renderPos, leftBlock, MaskType::Solid, tbl);
			}
			if (i + 1 < numMicros) {
				LevelCelBlock rightBlock { micros.mt[i + 1] };
				if (rightBlock.hasValue()) {
					RenderTile(surface, renderPos + Displacement { 32, 0 }, rightBlock, MaskType::Solid, tbl);
				}
			}
			renderPos.y -= 32;
		}

		std::vector<ColorRGBA> rgba(w * h);
		for (int y = 0; y < h; ++y) {
			const uint8_t *src = surface.at(0, y);
			for (int x = 0; x < w; ++x) {
				uint8_t idx = src[x];
				rgba[y * w + x] = (idx == 0) ? ColorRGBA{ 0, 0, 0, 0 } : pal[idx];
			}
		}
		SDL_FreeSurface(sdl_surf);

		std::string out_png = out_dir + "/piece_" + std::to_string(pieceId) + ".png";
		if (SavePNG(out_png, w, h, rgba)) {
			exported_count++;
		}
	}

	std::cout << "[Exporter] Successfully exported " << exported_count << " pieces to " << out_dir << std::endl;
	return 0;
}
