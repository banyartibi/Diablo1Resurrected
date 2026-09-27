#include "utils/cl2_to_clx.hpp"

#include <cstdint>
#include <cstring>

#include <vector>

#include "utils/clx_decode.hpp"
#include "utils/clx_encode.hpp"
#include "utils/endian_read.hpp"
#include "utils/endian_write.hpp"

namespace devilution {

uint16_t Cl2ToClx(const uint8_t *data, size_t size,
    PointerOrValue<uint16_t> widthOrWidths, std::vector<uint8_t> &clxData)
{
	if (!data || size < 8)
		return 0;

	uint32_t numGroups = 1;
	const uint32_t maybeNumFrames = LoadLE32(data);
	const uint8_t *groupBegin = data;

	// If it is a number of frames, then the last frame offset will be equal to the size of the file.
	if (maybeNumFrames * 4 + 8 > size || LoadLE32(&data[maybeNumFrames * 4 + 4]) != size) {
		// maybeNumFrames is the address of the first group, right after
		// the list of group offsets.
		if (maybeNumFrames % 4 != 0 || maybeNumFrames > size)
			return 0;
		numGroups = maybeNumFrames / 4;
		clxData.resize(maybeNumFrames);
	}

	// Transient buffer for a contiguous run of non-transparent pixels.
	std::vector<uint8_t> pixels;
	pixels.reserve(4096);

	const uint8_t *const dataEnd = data + size;

	for (size_t group = 0; group < numGroups; ++group) {
		uint32_t numFrames;
		if (numGroups == 1) {
			numFrames = maybeNumFrames;
		} else {
			if (group * 4 + 4 > size)
				break;
			const uint32_t groupOffset = LoadLE32(&data[group * 4]);
			if (groupOffset + 8 > size)
				break;
			groupBegin = &data[groupOffset];
			numFrames = LoadLE32(groupBegin);
			WriteLE32(&clxData[4 * group], static_cast<uint32_t>(clxData.size()));
		}

		if (groupBegin + 4 * (2 + static_cast<size_t>(numFrames)) > dataEnd)
			break;

		// CLX header: frame count, frame offset for each frame, file size
		const size_t clxDataOffset = clxData.size();
		clxData.resize(clxData.size() + 4 * (2 + static_cast<size_t>(numFrames)));
		WriteLE32(&clxData[clxDataOffset], numFrames);

		const uint32_t firstOffset = LoadLE32(&groupBegin[4]);
		if (firstOffset > size || &groupBegin[firstOffset] > dataEnd)
			break;

		const uint8_t *frameEnd = &groupBegin[firstOffset];
		for (size_t frame = 1; frame <= numFrames; ++frame) {
			const uint8_t *frameBegin = frameEnd;
			const uint32_t nextOffset = LoadLE32(&groupBegin[4 * (frame + 1)]);
			if (nextOffset > size || &groupBegin[nextOffset] > dataEnd || &groupBegin[nextOffset] < frameBegin)
				break;
			frameEnd = &groupBegin[nextOffset];
			if (frameBegin + 2 > frameEnd)
				break;

			WriteLE32(&clxData[clxDataOffset + 4 * frame],
			    static_cast<uint32_t>(clxData.size() - clxDataOffset));

			const uint16_t frameWidth = widthOrWidths.HoldsPointer() ? widthOrWidths.AsPointer()[frame - 1] : widthOrWidths.AsValue();

			const size_t frameHeaderPos = clxData.size();
			clxData.resize(clxData.size() + ClxFrameHeaderSize);
			WriteLE16(&clxData[frameHeaderPos], ClxFrameHeaderSize);
			WriteLE16(&clxData[frameHeaderPos + 2], frameWidth);

			unsigned transparentRunWidth = 0;
			int_fast16_t xOffset = 0;
			size_t frameHeight = 0;
			const uint16_t lineOffset = LoadLE16(frameBegin);
			if (frameBegin + lineOffset > frameEnd)
				break;
			const uint8_t *src = frameBegin + lineOffset;
			while (src < frameEnd) {
				auto remainingWidth = static_cast<int_fast16_t>(frameWidth) - xOffset;
				while (remainingWidth > 0 && src < frameEnd) {
					const uint8_t control = *src++;
					if (!IsClxOpaque(control)) {
						if (!pixels.empty()) {
							AppendClxPixelsOrFillRun(pixels.data(), pixels.size(), clxData);
							pixels.clear();
						}
						transparentRunWidth += control;
						remainingWidth -= control;
					} else if (IsClxOpaqueFill(control)) {
						if (src >= frameEnd) break;
						AppendClxTransparentRun(transparentRunWidth, clxData);
						transparentRunWidth = 0;
						const uint8_t width = GetClxOpaqueFillWidth(control);
						const uint8_t color = *src++;
						pixels.insert(pixels.end(), width, color);
						remainingWidth -= width;
					} else {
						AppendClxTransparentRun(transparentRunWidth, clxData);
						transparentRunWidth = 0;
						const uint8_t width = GetClxOpaquePixelsWidth(control);
						if (src + width > frameEnd) break;
						pixels.insert(pixels.end(), src, src + width);
						src += width;
						remainingWidth -= width;
					}
				}

				const auto skipSize = GetSkipSize(remainingWidth, static_cast<int_fast16_t>(frameWidth));
				xOffset = skipSize.xOffset;
				frameHeight += skipSize.wholeLines;
			}
			if (!pixels.empty()) {
				AppendClxPixelsOrFillRun(pixels.data(), pixels.size(), clxData);
				pixels.clear();
			}
			AppendClxTransparentRun(transparentRunWidth, clxData);

			WriteLE16(&clxData[frameHeaderPos + 4], static_cast<uint16_t>(frameHeight));
		}

		WriteLE32(&clxData[clxDataOffset + 4 * (1 + static_cast<size_t>(numFrames))], static_cast<uint32_t>(clxData.size() - clxDataOffset));
	}
	return numGroups == 1 ? 0 : numGroups;
}

} // namespace devilution
