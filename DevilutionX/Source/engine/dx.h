/**
 * @file dx.h
 *
 * Interface of functions setting up the graphics pipeline.
 */
#pragma once

#include "engine.h"

namespace devilution {

/** Whether we render directly to the screen surface, i.e. `PalSurface == GetOutputSurface()` */
extern bool RenderDirectlyToOutputSurface;

extern SDL_Surface *PalSurface;

Surface GlobalBackBuffer();

void dx_init();
void dx_cleanup();
void CreateBackBuffer();
void InitPalette();
void BltFast(SDL_Rect *srcRect, SDL_Rect *dstRect);
void Blit(SDL_Surface *src, SDL_Rect *srcRect, SDL_Rect *dstRect);
enum class ShaderStyle {
	AI_Neural_CNN = 0,
	AI_Neural_Bloom = 1,
	xBRZ_Vector = 2,
	xBRZ_Bloom = 3,
	Anime4K_Line = 4,
	Scale3X_SABR = 5,
	FSR_Ultra_Smooth = 6,
	FSR_CMAA2_Clean = 7,
	Bilateral_Denoise = 8,
	Dark_CRT_Royale = 9,
	Flat_CRT_Trinitron = 10,
	Vanilla_PixelArt = 11,
};
extern ShaderStyle CurrentShaderStyle;
void ToggleShaderStyle();
void NextShaderStyle();
void PreviousShaderStyle();

enum class ColorProfile : int32_t {
	D4_Dark_Gothic = 0,
	Hellish_Crimson = 1,
	High_Contrast_Vibrant = 2,
	Cold_Crypt = 3,
	Neutral_1996_Classic = 4,
};
extern ColorProfile CurrentColorProfile;
void NextColorProfile();
void PreviousColorProfile();

enum class AtmosphereFxMode : int32_t {
	All_On = 0,
	Lights_And_Mist = 1,
	Shadows_And_Wetness = 2,
	Off = 3,
};
extern AtmosphereFxMode CurrentAtmosphereFx;
void NextAtmosphereFx();
void PreviousAtmosphereFx();

void RenderPresent();
void PaletteGetEntries(int dwNumEntries, SDL_Color *lpEntries);

} // namespace devilution
