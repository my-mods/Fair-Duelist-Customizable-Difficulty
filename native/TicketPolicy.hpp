// MIT. Coordinated attack capacity; held tickets are never revoked.
#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
namespace Tickets {
struct Pool {uint8_t original{},written{};int held{};};
inline std::array<uint8_t,2> capacities(const std::array<Pool,2>& pools,int limit) {
    std::array<uint8_t,2> out{};
    for(int i=0;i<2;++i) {
        const int target=limit ? (i==0 ? 1 : limit-1) : pools[i].original;
        const int room=limit ? std::max(0,limit-pools[1-i].held) : target;
        out[i]=uint8_t(std::max(pools[i].held,std::min(target,room)));
    }
    return out;
}
}
