#include "engine/load_cl2.hpp"

#include <cstdint>
#include <memory>
#include <utility>

#include "engine/load_clx.hpp"
#include "engine/load_file.hpp"
#include "mpq/mpq_common.hpp"
#include "utils/cl2_to_clx.hpp"
#include "utils/log.hpp"
#include "utils/str_cat.hpp"

namespace devilution {

OwnedClxSpriteListOrSheet LoadCl2ListOrSheet(const char *pszName, PointerOrValue<uint16_t> widthOrWidths)
{
	char clxPath[MaxMpqPathSize];
	*BufCopy(clxPath, pszName, ".clx") = '\0';
	OptionalOwnedClxSpriteListOrSheet clx = LoadOptionalClxListOrSheet(clxPath);
	if (clx) {
		Log("Loaded HD CLX Replacement: {}", clxPath);
		return std::move(*clx);
	}

	char path[MaxMpqPathSize];
	*BufCopy(path, pszName, DEVILUTIONX_CL2_EXT) = '\0';
	size_t size;
	std::unique_ptr<uint8_t[]> data = LoadFileInMem<uint8_t>(path, &size);
	return Cl2ToClx(std::move(data), size, widthOrWidths);
}

} // namespace devilution
