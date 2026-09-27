#pragma once

#include <string>
#include <vector>
#include <memory>
#include <unordered_map>
#include <SDL.h>

#include "engine/point.hpp"
#include "engine/size.hpp"

namespace devilution {

struct D1DEEntity {
    std::string textureKey;
    Point screenPos;
    Size size;
    Point anchor; // Anchor offset relative to top-left (e.g. { width/2, height })
    uint8_t r = 255;
    uint8_t g = 255;
    uint8_t b = 255;
    uint8_t a = 255;
};
using D2REntity = D1DEEntity;

class D1DERenderEngine {
public:
    static D1DERenderEngine &GetInstance();

    void Init(SDL_Renderer *renderer, const std::string &assetsBasePath);
    void QueueEntity(const std::string &textureKey, Point screenPos, Size size, Point anchor, uint8_t r = 255, uint8_t g = 255, uint8_t b = 255, uint8_t a = 255);
    void ClearQueue();
    void RenderEntities(SDL_Renderer *renderer);

    SDL_Texture *GetOrLoadTexture(SDL_Renderer *renderer, const std::string &key, const std::string &filePath);

private:
    D1DERenderEngine() = default;
    ~D1DERenderEngine();

    std::string basePath;
    std::vector<D1DEEntity> queue;
    std::unordered_map<std::string, SDL_Texture *> textures;
};
using D2RRenderEngine = D1DERenderEngine;

void D1DE_Init(SDL_Renderer *renderer);
void D1DE_QueueEntity(const std::string &textureKey, Point screenPos, Size size, Point anchor, uint8_t r = 255, uint8_t g = 255, uint8_t b = 255, uint8_t a = 255);
void D1DE_ClearQueue();
void D1DE_RenderEntities(SDL_Renderer *renderer);

// Backward-compatibility aliases
inline void D2R_Init(SDL_Renderer *renderer) { D1DE_Init(renderer); }
inline void D2R_QueueEntity(const std::string &textureKey, Point screenPos, Size size, Point anchor, uint8_t r = 255, uint8_t g = 255, uint8_t b = 255, uint8_t a = 255) {
    D1DE_QueueEntity(textureKey, screenPos, size, anchor, r, g, b, a);
}
inline void D2R_ClearQueue() { D1DE_ClearQueue(); }
inline void D2R_RenderEntities(SDL_Renderer *renderer) { D1DE_RenderEntities(renderer); }

} // namespace devilution
