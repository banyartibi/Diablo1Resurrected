#include "engine/render_d2r.hpp"
#include <iostream>
#include <vector>
#include <filesystem>
#include <png.h>
#include "utils/log.hpp"

namespace fs = std::filesystem;

namespace devilution {

namespace {

SDL_Surface *LoadPngSurface(const std::string &path)
{
    FILE *fp = fopen(path.c_str(), "rb");
    if (!fp) return nullptr;

    png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
    if (!png) { fclose(fp); return nullptr; }

    png_infop info = png_create_info_struct(png);
    if (!info) { png_destroy_read_struct(&png, nullptr, nullptr); fclose(fp); return nullptr; }

    if (setjmp(png_jmpbuf(png))) {
        png_destroy_read_struct(&png, &info, nullptr);
        fclose(fp);
        return nullptr;
    }

    png_init_io(png, fp);
    png_read_info(png, info);

    int width = png_get_image_width(png, info);
    int height = png_get_image_height(png, info);
    png_byte color_type = png_get_color_type(png, info);
    png_byte bit_depth = png_get_bit_depth(png, info);

    if (bit_depth == 16)
        png_set_strip_16(png);
    if (color_type == PNG_COLOR_TYPE_PALETTE)
        png_set_palette_to_rgb(png);
    if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8)
        png_set_expand_gray_1_2_4_to_8(png);
    if (png_get_valid(png, info, PNG_INFO_tRNS))
        png_set_tRNS_to_alpha(png);
    if (color_type == PNG_COLOR_TYPE_RGB || color_type == PNG_COLOR_TYPE_GRAY)
        png_set_add_alpha(png, 0xFF, PNG_FILLER_AFTER);

    png_read_update_info(png, info);

    SDL_Surface *surface = SDL_CreateRGBSurfaceWithFormat(0, width, height, 32, SDL_PIXELFORMAT_RGBA32);
    if (!surface) {
        png_destroy_read_struct(&png, &info, nullptr);
        fclose(fp);
        return nullptr;
    }

    std::vector<png_bytep> row_pointers(height);
    for (int y = 0; y < height; ++y) {
        row_pointers[y] = (png_bytep)((uint8_t *)surface->pixels + y * surface->pitch);
    }

    png_read_image(png, row_pointers.data());
    png_destroy_read_struct(&png, &info, nullptr);
    fclose(fp);

    return surface;
}

} // namespace

D2RRenderEngine &D2RRenderEngine::GetInstance()
{
    static D2RRenderEngine instance;
    return instance;
}

D2RRenderEngine::~D2RRenderEngine()
{
    for (auto &pair : textures) {
        if (pair.second != nullptr) {
            SDL_DestroyTexture(pair.second);
        }
    }
    textures.clear();
}

void D2RRenderEngine::Init(SDL_Renderer *renderer, const std::string &assetsBasePath)
{
    basePath = assetsBasePath;
    Log("D2R Render Engine initialized with assets path: {}", basePath);
}

void D2RRenderEngine::QueueEntity(const std::string &textureKey, Point screenPos, Size size, Point anchor, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    queue.push_back(D2REntity{ textureKey, screenPos, size, anchor, r, g, b, a });
}

void D2RRenderEngine::ClearQueue()
{
    queue.clear();
}

SDL_Texture *D2RRenderEngine::GetOrLoadTexture(SDL_Renderer *renderer, const std::string &key, const std::string &filePath)
{
    auto it = textures.find(key);
    if (it != textures.end()) {
        return it->second;
    }

    if (!fs::exists(filePath)) {
        return nullptr;
    }

    SDL_Surface *surface = LoadPngSurface(filePath);
    if (!surface) {
        Log("D2R failed to load image: {}", filePath);
        return nullptr;
    }

    SDL_Texture *tex = SDL_CreateTextureFromSurface(renderer, surface);
    SDL_FreeSurface(surface);

    if (tex) {
        SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_BLEND);
        textures[key] = tex;
        Log("D2R loaded 32-bit GPU texture: {} (key: {})", filePath, key);
    }

    return tex;
}

void D2RRenderEngine::RenderEntities(SDL_Renderer *renderer)
{
    if (queue.empty() || renderer == nullptr)
        return;

    if (basePath.empty()) {
        Init(renderer, "/home/biti/antigravity/magical-bell/assets/d2r");
    }

    for (const auto &entity : queue) {
        std::string fullPath = basePath + "/" + entity.textureKey + ".png";
        SDL_Texture *tex = GetOrLoadTexture(renderer, entity.textureKey, fullPath);
        if (!tex) {
            // Fallback 1: frame 0 of same direction
            auto slashPos = entity.textureKey.find('/');
            auto framePos = entity.textureKey.find("_frame_");
            if (slashPos != std::string::npos && framePos != std::string::npos) {
                std::string fallbackKey1 = entity.textureKey.substr(0, framePos) + "_frame_0";
                tex = GetOrLoadTexture(renderer, fallbackKey1, basePath + "/" + fallbackKey1 + ".png");
            }
        }
        if (!tex) {
            // Fallback 2: base entity name (e.g. warrior or skeleton)
            auto slashPos = entity.textureKey.find('/');
            if (slashPos != std::string::npos) {
                std::string baseKey = entity.textureKey.substr(0, slashPos);
                if (baseKey.rfind("warrior", 0) == 0) baseKey = "warrior";
                if (baseKey.rfind("skeleton", 0) == 0) baseKey = "skeleton";
                tex = GetOrLoadTexture(renderer, baseKey, basePath + "/" + baseKey + ".png");
            }
        }
        if (!tex)
            continue;

        SDL_Rect dstRect;
        dstRect.x = entity.screenPos.x - entity.anchor.x;
        dstRect.y = entity.screenPos.y - entity.anchor.y;
        dstRect.w = entity.size.width;
        dstRect.h = entity.size.height;

        SDL_SetTextureColorMod(tex, entity.r, entity.g, entity.b);
        SDL_SetTextureAlphaMod(tex, entity.a);

        SDL_RenderCopy(renderer, tex, nullptr, &dstRect);
    }

    ClearQueue();
}

void D2R_Init(SDL_Renderer *renderer)
{
    D2RRenderEngine::GetInstance().Init(renderer, "/home/biti/antigravity/magical-bell/assets/d2r");
}

void D2R_QueueEntity(const std::string &textureKey, Point screenPos, Size size, Point anchor, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    D2RRenderEngine::GetInstance().QueueEntity(textureKey, screenPos, size, anchor, r, g, b, a);
}

void D2R_ClearQueue()
{
    D2RRenderEngine::GetInstance().ClearQueue();
}

void D2R_RenderEntities(SDL_Renderer *renderer)
{
    D2RRenderEngine::GetInstance().RenderEntities(renderer);
}

} // namespace devilution
