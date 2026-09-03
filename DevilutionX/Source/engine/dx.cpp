/**
 * @file dx.cpp
 *
 * Implementation of functions setting up the graphics pipeline.
 */
#include "engine/dx.h"

#include <SDL.h>
#include <cstdint>

#include "controls/plrctrls.h"
#include "engine.h"
#include "options.h"
#include "utils/display.h"
#include "utils/log.hpp"
#include "utils/sdl_wrap.h"
#include "engine/render_d2r.hpp"
#include "engine/render_vulkan/render_vulkan.hpp"
#include "engine/render_bridge.hpp"

#ifndef USE_SDL1
#include "controls/touch/renderers.h"
#endif

#ifndef _WIN32
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#ifdef __3DS__
#include <3ds.h>
#endif

namespace devilution {

int refreshDelay;
SDL_Renderer *renderer;
#ifndef USE_SDL1
SDLTextureUniquePtr texture;
SDLTextureUniquePtr bloomTexture;
#endif

/** Currently active palette */
SDLPaletteUniquePtr Palette;
unsigned int pal_surface_palette_version = 0;

/** 24-bit renderer texture surface */
SDLSurfaceUniquePtr RendererTextureSurface;

/** 8-bit surface that we render to */
SDL_Surface *PalSurface;
namespace {
SDLSurfaceUniquePtr PinnedPalSurface;
} // namespace

/** Whether we render directly to the screen surface, i.e. `PalSurface == GetOutputSurface()` */
bool RenderDirectlyToOutputSurface;

namespace {

bool CanRenderDirectlyToOutputSurface()
{
#ifdef USE_SDL1
#ifdef SDL1_FORCE_DIRECT_RENDER
	return true;
#else
	auto *outputSurface = GetOutputSurface();
	return ((outputSurface->flags & SDL_DOUBLEBUF) == SDL_DOUBLEBUF
	    && outputSurface->w == gnScreenWidth && outputSurface->h == gnScreenHeight
	    && outputSurface->format->BitsPerPixel == 8);
#endif
#else // !USE_SDL1
	return false;
#endif
}

/**
 * @brief Limit FPS to avoid high CPU load, use when v-sync isn't available
 */
void LimitFrameRate()
{
	if (*sgOptions.Graphics.frameRateControl != FrameRateControl::CPUSleep)
		return;
	static uint32_t frameDeadline;
	uint32_t tc = SDL_GetTicks() * 1000;
	uint32_t v = 0;
	if (frameDeadline > tc) {
		v = tc % refreshDelay;
		SDL_Delay(v / 1000 + 1); // ceil
	}
	frameDeadline = tc + v + refreshDelay;
}

} // namespace

void dx_init()
{
#ifndef USE_SDL1
	SDL_RaiseWindow(ghMainWnd);
	SDL_ShowWindow(ghMainWnd);
#endif

	palette_init();
	CreateBackBuffer();
	pal_surface_palette_version = 1;
}

Surface GlobalBackBuffer()
{
	return Surface(PalSurface, SDL_Rect { 0, 0, gnScreenWidth, gnScreenHeight });
}

void dx_cleanup()
{
#ifndef USE_SDL1
	if (ghMainWnd != nullptr)
		SDL_HideWindow(ghMainWnd);
#endif

	PalSurface = nullptr;
	PinnedPalSurface = nullptr;
	Palette = nullptr;
	if (Vulkan_IsActive()) {
		Vulkan_Cleanup();
	}
#ifndef USE_SDL1
	bloomTexture = nullptr;
	texture = nullptr;
	if (*sgOptions.Graphics.upscale && renderer != nullptr)
		SDL_DestroyRenderer(renderer);
#endif
	SDL_DestroyWindow(ghMainWnd);
}

void CreateBackBuffer()
{
	if (CanRenderDirectlyToOutputSurface()) {
		Log("{}", "Will render directly to the SDL output surface");
		PalSurface = GetOutputSurface();
		RenderDirectlyToOutputSurface = true;
	} else {
		PinnedPalSurface = SDLWrap::CreateRGBSurfaceWithFormat(
		    /*flags=*/0,
		    /*width=*/gnScreenWidth,
		    /*height=*/gnScreenHeight,
		    /*depth=*/8,
		    SDL_PIXELFORMAT_INDEX8);
		PalSurface = PinnedPalSurface.get();
	}

#ifndef USE_SDL1
	// In SDL2, `PalSurface` points to the global `palette`.
	if (SDL_SetSurfacePalette(PalSurface, Palette.get()) < 0)
		ErrSdl();
#else
	// In SDL1, `PalSurface` owns its palette and we must update it every
	// time the global `palette` is changed. No need to do anything here as
	// the global `palette` doesn't have any colors set yet.
#endif
}

void InitPalette()
{
	Palette = SDLWrap::AllocPalette();
}

void BltFast(SDL_Rect *srcRect, SDL_Rect *dstRect)
{
	if (RenderDirectlyToOutputSurface)
		return;
	Blit(PalSurface, srcRect, dstRect);
}

void Blit(SDL_Surface *src, SDL_Rect *srcRect, SDL_Rect *dstRect)
{
	if (HeadlessMode)
		return;

	SDL_Surface *dst = GetOutputSurface();
#ifndef USE_SDL1
	if (SDL_BlitSurface(src, srcRect, dst, dstRect) < 0)
		ErrSdl();
#else
	if (!OutputRequiresScaling()) {
		if (SDL_BlitSurface(src, srcRect, dst, dstRect) < 0)
			ErrSdl();
		return;
	}

	SDL_Rect scaledDstRect;
	if (dstRect != NULL) {
		scaledDstRect = *dstRect;
		ScaleOutputRect(&scaledDstRect);
		dstRect = &scaledDstRect;
	}

	// Same pixel format: We can call BlitScaled directly.
	if (SDLBackport_PixelFormatFormatEq(src->format, dst->format)) {
		if (SDL_BlitScaled(src, srcRect, dst, dstRect) < 0)
			ErrSdl();
		return;
	}

	// If the surface has a color key, we must stretch first and can then call BlitSurface.
	if (SDL_HasColorKey(src)) {
		SDLSurfaceUniquePtr stretched = SDLWrap::CreateRGBSurface(SDL_SWSURFACE, dstRect->w, dstRect->h, src->format->BitsPerPixel,
		    src->format->Rmask, src->format->Gmask, src->format->BitsPerPixel, src->format->Amask);
		SDL_SetColorKey(stretched.get(), SDL_SRCCOLORKEY, src->format->colorkey);
		if (src->format->palette != NULL)
			SDL_SetPalette(stretched.get(), SDL_LOGPAL, src->format->palette->colors, 0, src->format->palette->ncolors);
		SDL_Rect stretched_rect = { 0, 0, dstRect->w, dstRect->h };
		if (SDL_SoftStretch(src, srcRect, stretched.get(), &stretched_rect) < 0
		    || SDL_BlitSurface(stretched.get(), &stretched_rect, dst, dstRect) < 0) {
			ErrSdl();
		}
		return;
	}

	// A surface with a non-output pixel format but without a color key needs scaling.
	// We can convert the format and then call BlitScaled.
	SDLSurfaceUniquePtr converted = SDLWrap::ConvertSurface(src, dst->format, 0);
	if (SDL_BlitScaled(converted.get(), srcRect, dst, dstRect) < 0)
		ErrSdl();
#endif
}

ShaderStyle CurrentShaderStyle = ShaderStyle::AI_Neural_Bloom;
#ifndef USE_SDL1
SDLTextureUniquePtr crtScanlineTexture;
#endif

void NextShaderStyle()
{
	CurrentShaderStyle = static_cast<ShaderStyle>((static_cast<int>(CurrentShaderStyle) + 1) % 12);
}

void PreviousShaderStyle()
{
	int cur = static_cast<int>(CurrentShaderStyle);
	cur = (cur + 11) % 12;
	CurrentShaderStyle = static_cast<ShaderStyle>(cur);
}

ColorProfile CurrentColorProfile = ColorProfile::D4_Dark_Gothic;

void NextColorProfile()
{
	CurrentColorProfile = static_cast<ColorProfile>((static_cast<int>(CurrentColorProfile) + 1) % 5);
}

void PreviousColorProfile()
{
	int cur = static_cast<int>(CurrentColorProfile);
	cur = (cur + 4) % 5;
	CurrentColorProfile = static_cast<ColorProfile>(cur);
}

AtmosphereFxMode CurrentAtmosphereFx = AtmosphereFxMode::All_On;

void NextAtmosphereFx()
{
	CurrentAtmosphereFx = static_cast<AtmosphereFxMode>((static_cast<int>(CurrentAtmosphereFx) + 1) % 4);
}

void PreviousAtmosphereFx()
{
	int cur = static_cast<int>(CurrentAtmosphereFx);
	cur = (cur + 3) % 4;
	CurrentAtmosphereFx = static_cast<AtmosphereFxMode>(cur);
}

void ToggleShaderStyle()
{
	NextShaderStyle();
}

void RenderPresent()
{
	if (HeadlessMode)
		return;

	SDL_Surface *surface = GetOutputSurface();

	if (!gbActive && !gbGodotBridgeActive) {
		LimitFrameRate();
		return;
	}

	if (Vulkan_IsActive()) {
		Vulkan_RenderPresent(surface);
		return;
	}

#ifndef USE_SDL1
	if (renderer != nullptr) {
		if (SDL_UpdateTexture(texture.get(), nullptr, surface->pixels, surface->pitch) <= -1) { // pitch is 2560
			ErrSdl();
		}

		// Initialize Bloom Texture if needed:
		if (bloomTexture == nullptr && renderer != nullptr) {
			bloomTexture = SDLWrap::CreateTexture(
			    renderer,
			    DEVILUTIONX_DISPLAY_TEXTURE_FORMAT,
			    SDL_TEXTUREACCESS_TARGET,
			    std::max(1, gnScreenWidth / 2),
			    std::max(1, gnScreenHeight / 2));
			if (bloomTexture) {
				SDL_SetTextureBlendMode(bloomTexture.get(), SDL_BLENDMODE_ADD);
			}
		}

		// Initialize CRT Scanline Texture if needed:
		if (crtScanlineTexture == nullptr && renderer != nullptr) {
			SDL_Surface *scanlineSurface = SDL_CreateRGBSurfaceWithFormat(0, 4, 4, 32, SDL_PIXELFORMAT_RGBA8888);
			if (scanlineSurface) {
				Uint32 *pixels = static_cast<Uint32 *>(scanlineSurface->pixels);
				for (int y = 0; y < 4; ++y) {
					for (int x = 0; x < 4; ++x) {
						// Alternating scanlines
						if (y % 2 == 1) {
							pixels[y * 4 + x] = SDL_MapRGBA(scanlineSurface->format, 0, 0, 0, 115);
						} else {
							pixels[y * 4 + x] = SDL_MapRGBA(scanlineSurface->format, 0, 0, 0, 0);
						}
					}
				}
				crtScanlineTexture = SDLTextureUniquePtr { SDL_CreateTextureFromSurface(renderer, scanlineSurface) };
				if (crtScanlineTexture) {
					SDL_SetTextureBlendMode(crtScanlineTexture.get(), SDL_BLENDMODE_BLEND);
				}
				SDL_FreeSurface(scanlineSurface);
			}
		}

		if (bloomTexture != nullptr && CurrentShaderStyle != ShaderStyle::Vanilla_PixelArt) {
			// Pass 1: Render downscaled scene to bloom target
			SDL_SetRenderTarget(renderer, bloomTexture.get());
			SDL_RenderCopy(renderer, texture.get(), nullptr, nullptr);

			// Pass 2: Switch back to screen output
			SDL_SetRenderTarget(renderer, nullptr);
		}

		// Clear buffer
		if (SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) <= -1) {
			ErrSdl();
		}

		if (SDL_RenderClear(renderer) <= -1) {
			ErrSdl();
		}

		// Draw base game scene
		if (SDL_RenderCopy(renderer, texture.get(), nullptr, nullptr) <= -1) {
			ErrSdl();
		}

		// Mode A: FSR 4K Ultra Luminous Bloom & Torchlight HDR Glow
		if (CurrentShaderStyle == ShaderStyle::FSR_Ultra_Smooth || CurrentShaderStyle == ShaderStyle::xBRZ_Bloom) {
			if (bloomTexture != nullptr) {
				// Pass 1: Broad Warm Ambient Torchlight Glow
				SDL_SetTextureColorMod(bloomTexture.get(), 255, 200, 130);
				SDL_SetTextureAlphaMod(bloomTexture.get(), 110);
				SDL_RenderCopy(renderer, bloomTexture.get(), nullptr, nullptr);

				// Pass 2: Specular Fire & Magic Core Highlight
				SDL_SetTextureColorMod(bloomTexture.get(), 255, 240, 210);
				SDL_SetTextureAlphaMod(bloomTexture.get(), 65);
				SDL_RenderCopy(renderer, bloomTexture.get(), nullptr, nullptr);
			}

			// Pass 3: Subtle Gothic Edge Vignette
			SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
			SDL_SetRenderDrawColor(renderer, 0, 0, 0, 35);
			// Left & right edge shade
			SDL_Rect leftVignette { 0, 0, gnScreenWidth / 8, gnScreenHeight };
			SDL_Rect rightVignette { gnScreenWidth - (gnScreenWidth / 8), 0, gnScreenWidth / 8, gnScreenHeight };
			SDL_RenderFillRect(renderer, &leftVignette);
			SDL_RenderFillRect(renderer, &rightVignette);
		}
		// Mode B: Authentic High-Contrast CRT Scanlines & Phosphor Glow
		else if (CurrentShaderStyle == ShaderStyle::Dark_CRT_Royale || CurrentShaderStyle == ShaderStyle::Flat_CRT_Trinitron) {
			// Phosphor glow on torches and bright UI
			if (bloomTexture != nullptr) {
				SDL_SetTextureColorMod(bloomTexture.get(), 180, 225, 255);
				SDL_SetTextureAlphaMod(bloomTexture.get(), 50);
				SDL_RenderCopy(renderer, bloomTexture.get(), nullptr, nullptr);
			}
			// High-Contrast CRT Scanlines
			SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
			SDL_SetRenderDrawColor(renderer, 0, 0, 0, 105);
			for (int y = 0; y < gnScreenHeight; y += 2) {
				SDL_RenderDrawLine(renderer, 0, y, gnScreenWidth, y);
			}
		}

		if (ControlMode == ControlTypes::VirtualGamepad) {
			RenderVirtualGamepad(renderer);
		}
		SDL_RenderPresent(renderer);

		if (*sgOptions.Graphics.frameRateControl != FrameRateControl::VerticalSync) {
			LimitFrameRate();
		}
	} else {
		if (ControlMode == ControlTypes::VirtualGamepad) {
			RenderVirtualGamepad(surface);
		}
		if (SDL_UpdateWindowSurface(ghMainWnd) <= -1) {
			ErrSdl();
		}
		LimitFrameRate();
	}
#else
	if (SDL_Flip(surface) <= -1) {
		ErrSdl();
	}
	if (RenderDirectlyToOutputSurface)
		PalSurface = GetOutputSurface();
	LimitFrameRate();
#endif
}

void PaletteGetEntries(int dwNumEntries, SDL_Color *lpEntries)
{
	for (int i = 0; i < dwNumEntries; i++) {
		lpEntries[i] = system_palette[i];
	}
}
} // namespace devilution
