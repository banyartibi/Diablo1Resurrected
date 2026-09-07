/**
 * @file minitext.h
 *
 * Interface of scrolling dialog text.
 */
#pragma once

#include "engine.h"
#include "textdat.h"

#include <string>
#include <vector>

namespace devilution {

/** Specify if the quest dialog window is being shown */
extern bool qtextflag;

/**
 * @brief Free the resouces used by the quest dialog window
 */
void FreeQuestText();

/**
 * @brief Load the resouces used by the quest dialog window, and initialize it's state
 */
void InitQuestText();

/**
 * @brief Start the given naration
 * @param m Index of narration from the Texts table
 */
void InitQTextMsg(_speech_id m);

/**
 * @brief Draw the quest dialog window decoration and background.
 */
void DrawQTextBack(const Surface &out);

/**
 * @brief Draw the quest dialog window text.
 */
void DrawQText(const Surface &out);

/**
 * @brief Get formatted speech text lines for the Godot native dialogue overlay.
 */
std::vector<std::string> GetRawQTextLines();

/**
 * @brief Dismiss active quest speech narration.
 */
void DismissRawQText();

} // namespace devilution
