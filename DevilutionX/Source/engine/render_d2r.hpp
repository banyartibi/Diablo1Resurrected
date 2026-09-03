#pragma once

#include <string>
#include <vector>
#include <memory>
#include <unordered_map>
#include <SDL.h>

#include "engine/point.hpp"
#include "engine/size.hpp"

namespace devilution {

struct D2REntity {
    std::string textureKey;
    Point screenPos;
    Size size;
    Point anchor; // Anchor offset relative to top-left (e.g. { width/2, height })
    uint8_t r = 255;
    uint8_t g = 255;
    uint8_t b = 255;
    uint8_t a = 255;
};

class D2RRenderEngine {
public:
    static D2RRenderEngine &GetInstance();

    void Init(SDL_Renderer *renderer, const std::string &assetsBasePath);
    void QueueEntity(const std::string &textureKey, Point screenPos, Size size, Point anchor, uint8_t r = 255, uint8_t g = 255, uint8_t b = 255, uint8_t a = 255);
    void ClearQueue();
    void RenderEntities(SDL_Renderer *renderer);

    SDL_Texture *GetOrLoadTexture(SDL_Renderer *renderer, const std::string &key, const std::string &filePath);

private:
    D2RRenderEngine() = default;
    ~D2RRenderEngine();

    std::string basePath;
    std::vector<D2REntity> queue;
    std::unordered_map<std::string, SDL_Texture *> textures;
};

void D2R_Init(SDL_Renderer *renderer);
void D2R_QueueEntity(const std::string &textureKey, Point screenPos, Size size, Point anchor, uint8_t r = 255, uint8_t g = 255, uint8_t b = 255, uint8_t a = 255);
void D2R_ClearQueue();
void D2R_RenderEntities(SDL_Renderer *renderer);

} // namespace devilution
