#include "engine/load_cel.hpp"

#include <cstddef>
#include <cstdint>

#ifdef DEBUG_CEL_TO_CL2_SIZE
#include <iostream>
#endif

#include "engine/load_clx.hpp"
#include "mpq/mpq_common.hpp"
#include "utils/log.hpp"
#include "utils/str_cat.hpp"

#ifdef UNPACKED_MPQS
#include "engine/load_clx.hpp"
#else
#include "engine/load_file.hpp"
#include "utils/cel_to_clx.hpp"
#endif

namespace devilution {

OwnedClxSpriteListOrSheet LoadCelListOrSheet(const char *pszName, PointerOrValue<uint16_t> widthOrWidths)
{
	char clxPath[MaxMpqPathSize];
	*BufCopy(clxPath, pszName, ".clx") = '\0';
	OptionalOwnedClxSpriteListOrSheet clx = LoadOptionalClxListOrSheet(clxPath);
	if (clx) {
		Log("Loaded HD CLX Replacement for CEL: {}", clxPath);
		return std::move(*clx);
	}

	char path[MaxMpqPathSize];
	*BufCopy(path, pszName, DEVILUTIONX_CEL_EXT) = '\0';
#ifdef UNPACKED_MPQS
	return LoadClxListOrSheet(path);
#else
	size_t size = 0;
	std::unique_ptr<uint8_t[]> data = LoadFileInMem<uint8_t>(path, &size);
	if (!data || size < 8) {
		return OwnedClxSpriteListOrSheet { nullptr, 0 };
	}
#ifdef DEBUG_CEL_TO_CL2_SIZE
	std::cout << path;
#endif
	return CelToClx(data.get(), size, widthOrWidths);
#endif
}

} // namespace devilution
