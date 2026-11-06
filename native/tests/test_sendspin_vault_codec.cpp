#include "sendspin_vault_codec.hpp"
#include <cassert>
#include <random>
int main() {
    using namespace shield_sendspin_vault_codec;
    ShieldSendspinBlobs src{{"keypair",std::vector<uint8_t>(32,17)},{"rec_11",std::vector<uint8_t>(64,19)}};
    std::vector<uint8_t> encoded;
    assert(encode(src,encoded));
    ShieldSendspinBlobs output;
    assert(decode(encoded,output) && output==src);
    for (size_t n=0;n<encoded.size();++n) {
        auto partial=std::vector<uint8_t>(encoded.begin(),encoded.begin()+n);
        auto keep=src;
        assert(!decode(partial,keep) && keep==src);
    }
    auto bad=encoded; bad.push_back(0);
    output=src; assert(!decode(bad,output) && output==src);
    bad=encoded; bad[3]='2'; assert(!decode(bad,output));
    bad=encoded; bad[4]=18; assert(!decode(bad,output));
    assert(!encode({{"invalid key",{1}}},encoded));
    assert(!encode({{"keypair",std::vector<uint8_t>(65,1)}},encoded));
    std::mt19937 rng(42);
    for (int i=0;i<10000;++i) {
        std::vector<uint8_t> bytes(rng()%256);
        for (auto &b:bytes) b=static_cast<uint8_t>(rng());
        ShieldSendspinBlobs value;
        if (decode(bytes,value)) { std::vector<uint8_t> rt; assert(encode(value,rt)); }
    }
}
