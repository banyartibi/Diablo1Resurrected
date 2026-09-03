/**
 * @file render_vulkan.hpp
 *
 * Native Vulkan 2D/32-bit Presentation Engine for DevilutionX.
 */
#pragma once

#include <SDL.h>
#include <cstdint>

namespace devilution {

extern bool gbVulkanRequested;
extern float g_SmoothZoomFactor;

/**
 * @brief Check if Vulkan renderer is currently active.
 */
bool Vulkan_IsActive();

/**
 * @brief Initialize the Vulkan subsystem for the specified SDL window.
 * @param window Target SDL window
 * @param width Initial buffer width
 * @param height Initial buffer height
 * @return True if Vulkan initialization succeeded, false if fallback to OpenGL is required
 */
bool Vulkan_Init(SDL_Window *window, int width, int height);

/**
 * @brief Clean up all Vulkan resources (Swapchain, Pipelines, Device, Instance).
 */
void Vulkan_Cleanup();

/**
 * @brief Upload the 32-bit backbuffer surface and present to the screen via Vulkan swapchain.
 * @param surface The 32-bit RGBA surface from DevilutionX
 */
void Vulkan_RenderPresent(const SDL_Surface *surface);

} // namespace devilution
