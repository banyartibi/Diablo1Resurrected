/**
 * @file scrollrt.h
 *
 * Interface of functionality for rendering the dungeons, monsters and calling other render routines.
 */
#pragma once

#include <cstdint>

#include "engine.h"
#include "engine/animationinfo.h"
#include "engine/point.hpp"

namespace devilution {

enum class ZoomMode {
	Normal = 0,        // 1.0x (Wide)
	Balanced_1_5x = 1, // 1.5x (Intermediate / Köztes)
	Zoomed_2x = 2,     // 2.0x (Close)
	UltraClose_2_5x = 3, // 2.5x (Ultra Close)
	MacroClose_3x = 4    // 3.0x (Macro Close)
};

extern ZoomMode CurrentZoomMode;
void CycleZoomMode();
void ZoomInMode();
void ZoomOutMode();

extern int LightTableIndex;
extern bool AutoMapShowItems;
extern bool frameflag;

/**
 * @brief Returns the offset for the walking animation
 * @param animationInfo the current active walking animation
 * @param dir walking direction
 * @param cameraMode Adjusts the offset relative to the camera
 */
Displacement GetOffsetForWalking(const AnimationInfo &animationInfo, const Direction dir, bool cameraMode = false);

/**
 * @brief Clear cursor state
 */
void ClearCursor();

/**
 * @brief Shifting the view area along the logical grid
 *        Note: this won't allow you to shift between even and odd rows
 * @param x X offset
 * @param y Y offset
 * @param horizontal Shift the screen left or right
 * @param vertical Shift the screen up or down
 */
void ShiftGrid(int *x, int *y, int horizontal, int vertical);

/**
 * @brief Gets the number of rows covered by the main panel
 */
int RowsCoveredByPanel();

/**
 * @brief Translates any world tile coordinate and sub-tile offset into exact current screen pixels
 */
Point TileToScreenCoords(Point tilePosition, Displacement subTileOffset = {});

/**
 * @brief Calculate the offset needed for centering tiles in view area
 * @param offsetX Offset in pixels
 * @param offsetY Offset in pixels
 */
void CalcTileOffset(int *offsetX, int *offsetY);

/**
 * @brief Calculate the needed diamond tile to cover the view area
 * @param columns Tiles needed per row
 * @param rows Both even and odd rows
 */
void TilesInView(int *columns, int *rows);
void CalcViewportGeometry();

/**
 * @brief Render the whole screen black
 */
void ClearScreenBuffer();
#ifdef _DEBUG

/**
 * @brief Scroll the screen when mouse is close to the edge
 */
void ScrollView();
#endif

/**
 * @brief Initialize the FPS meter
 */
void EnableFrameCount();

/**
 * @brief Redraw screen
 */
void scrollrt_draw_game_screen();

/**
 * @brief Render the game
 */
void DrawAndBlit();

} // namespace devilution
