#include "utils/cel_to_clx.hpp"

#include <cstdint>
#include <cstring>

#include <vector>

#ifdef DEBUG_CEL_TO_CL2_SIZE
#include <iomanip>
#include <iostream>
#endif

#include "appfat.h"
#include "utils/clx_encode.hpp"
#include "utils/endian_read.hpp"
#include "utils/endian_write.hpp"

namespace devilution {

namespace {

constexpr bool IsCelTransparent(uint8_t control)
{
	constexpr uint8_t CelTransparentMin = 0x80;
	return control >= CelTransparentMin;
}

constexpr uint8_t GetCelTransparentWidth(uint8_t control)
{
	return -static_cast<int8_t>(control);
}

} // namespace

OwnedClxSpriteListOrSheet CelToClx(const uint8_t *data, size_t size, PointerOrValue<uint16_t> widthOrWidths)
{
	if (!data || size < 8)
		return OwnedClxSpriteListOrSheet { nullptr, 0 };

	// A CEL file either begins with:
	// 1. A CEL header.
	// 2. A list of offsets to frame groups (each group is a CEL file).
	size_t groupsHeaderSize = 0;
	uint32_t numGroups = 1;
	const uint32_t maybeNumFrames = LoadLE32(data);

	std::vector<uint8_t> cl2Data;

	// Most files become smaller with CL2. Allocate exactly enough bytes to avoid reallocation.
	// The only file that becomes larger is data\hf_logo3.cel, by exactly 4445 bytes.
	cl2Data.reserve(size + 4445);

	const uint8_t *const dataEnd = data + size;

	// If it is a number of frames, then the last frame offset will be equal to the size of the file.
	if (maybeNumFrames * 4 + 8 > size || LoadLE32(&data[maybeNumFrames * 4 + 4]) != size) {
		// maybeNumFrames is the address of the first group, right after
		// the list of group offsets.
		if (maybeNumFrames % 4 != 0 || maybeNumFrames > size)
			return OwnedClxSpriteListOrSheet { nullptr, 0 };
		numGroups = maybeNumFrames / 4;
		groupsHeaderSize = maybeNumFrames;
		data += groupsHeaderSize;
		cl2Data.resize(groupsHeaderSize);
	}

	for (size_t group = 0; group < numGroups; ++group) {
		if (data + 8 > dataEnd)
			break;
		uint32_t numFrames;
		if (numGroups == 1) {
			numFrames = maybeNumFrames;
		} else {
			numFrames = LoadLE32(data);
			WriteLE32(&cl2Data[4 * group], static_cast<uint32_t>(cl2Data.size()));
		}

		if (data + 4 * (2 + static_cast<size_t>(numFrames)) > dataEnd)
			break;

		// CL2 header: frame count, frame offset for each frame, file size
		const size_t cl2DataOffset = cl2Data.size();
		cl2Data.resize(cl2Data.size() + 4 * (2 + static_cast<size_t>(numFrames)));
		WriteLE32(&cl2Data[cl2DataOffset], numFrames);

		const uint32_t firstOffset = LoadLE32(&data[4]);
		if (firstOffset > size || data + firstOffset > dataEnd)
			break;

		const uint8_t *srcEnd = data + firstOffset;
		for (size_t frame = 1; frame <= numFrames; ++frame) {
			const uint8_t *src = srcEnd;
			const uint32_t nextOffset = LoadLE32(&data[4 * (frame + 1)]);
			if (nextOffset > size || data + nextOffset > dataEnd || data + nextOffset < src)
				break;
			srcEnd = data + nextOffset;
			WriteLE32(&cl2Data[cl2DataOffset + 4 * frame], static_cast<uint32_t>(cl2Data.size() - cl2DataOffset));

			// Skip CEL frame header if there is one.
			constexpr size_t CelFrameHeaderSize = 10;
			const bool celFrameHasHeader = (src + CelFrameHeaderSize <= srcEnd) && (LoadLE16(src) == CelFrameHeaderSize);
			if (celFrameHasHeader)
				src += CelFrameHeaderSize;

			const unsigned frameWidth = widthOrWidths.HoldsPointer() ? widthOrWidths.AsPointer()[frame - 1] : widthOrWidths.AsValue();

			// CLX frame header.
			const size_t frameHeaderPos = cl2Data.size();
			cl2Data.resize(cl2Data.size() + ClxFrameHeaderSize);
			WriteLE16(&cl2Data[frameHeaderPos], ClxFrameHeaderSize);
			WriteLE16(&cl2Data[frameHeaderPos + 2], frameWidth);

			unsigned transparentRunWidth = 0;
			size_t frameHeight = 0;
			while (src < srcEnd) {
				// Process line:
				for (unsigned remainingCelWidth = frameWidth; remainingCelWidth != 0;) {
					if (src >= srcEnd)
						break;
					uint8_t val = *src++;
					if (IsCelTransparent(val)) {
						val = GetCelTransparentWidth(val);
						transparentRunWidth += val;
					} else {
						AppendClxTransparentRun(transparentRunWidth, cl2Data);
						transparentRunWidth = 0;
						if (src + val > srcEnd) {
							val = static_cast<uint8_t>(srcEnd - src);
						}
						AppendClxPixelsOrFillRun(src, val, cl2Data);
						src += val;
					}
					if (val >= remainingCelWidth)
						break;
					remainingCelWidth -= val;
				}
				++frameHeight;
			}
			WriteLE16(&cl2Data[frameHeaderPos + 4], static_cast<uint16_t>(frameHeight));
			AppendClxTransparentRun(transparentRunWidth, cl2Data);
		}

		WriteLE32(&cl2Data[cl2DataOffset + 4 * (1 + static_cast<size_t>(numFrames))], static_cast<uint32_t>(cl2Data.size() - cl2DataOffset));
		data = srcEnd;
	}

	auto out = std::unique_ptr<uint8_t[]>(new uint8_t[cl2Data.size()]);
	memcpy(&out[0], cl2Data.data(), cl2Data.size());
#ifdef DEBUG_CEL_TO_CL2_SIZE
	std::cout << "\t" << size << "\t" << cl2Data.size() << "\t" << std::setprecision(1) << std::fixed << (static_cast<int>(cl2Data.size()) - static_cast<int>(size)) / ((float)size) * 100 << "%" << std::endl;
#endif
	return OwnedClxSpriteListOrSheet { std::move(out), static_cast<uint16_t>(numGroups == 1 ? 0 : numGroups) };
}

} // namespace devilution
