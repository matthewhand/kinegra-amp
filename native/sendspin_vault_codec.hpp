#pragma once
#include "sendspin_secure_persistence.hpp"
#include <algorithm>
// Versioned, bounded opaque snapshot. Actual secrecy/integrity belongs to the
// Android Keystore vault. Decoding never returns partial state on an error.
namespace shield_sendspin_vault_codec {
constexpr size_t max_bytes=4096;
inline bool encode(const ShieldSendspinBlobs &items,std::vector<uint8_t> &out) {
    if (items.size()>17) return false;
    std::vector<uint8_t> data={'S','S','V','1',static_cast<uint8_t>(items.size())};
    for (const auto &entry:items) {
        if (entry.first.empty() || entry.first.size()>12 || entry.second.empty() || entry.second.size()>64) return false;
        if (!std::all_of(entry.first.begin(),entry.first.end(),[](char c){return (c>='a' && c<='z') || (c>='0' && c<='9') || c=='_';})) return false;
        data.push_back(static_cast<uint8_t>(entry.first.size()));
        data.insert(data.end(),entry.first.begin(),entry.first.end());
        data.push_back(static_cast<uint8_t>(entry.second.size()));
        data.insert(data.end(),entry.second.begin(),entry.second.end());
        if (data.size()>max_bytes) return false;
    }
    out=std::move(data); return true;
}
inline bool decode(const std::vector<uint8_t> &in,ShieldSendspinBlobs &out) {
    if (in.size()<5 || in.size()>max_bytes || in[0]!='S' || in[1]!='S' || in[2]!='V' || in[3]!='1' || in[4]>17) return false;
    ShieldSendspinBlobs result;
    size_t at=5;
    for (size_t i=0;i<in[4];++i) {
        if (at>=in.size()) return false;
        size_t key_len=in[at++];
        if (!key_len || key_len>12 || key_len>in.size()-at) return false;
        std::string key(in.begin()+at,in.begin()+at+key_len); at+=key_len;
        if (!std::all_of(key.begin(),key.end(),[](char c){return (c>='a' && c<='z') || (c>='0' && c<='9') || c=='_';}) || at>=in.size()) return false;
        size_t value_len=in[at++];
        if (!value_len || value_len>64 || value_len>in.size()-at || result.count(key)) return false;
        result.emplace(std::move(key),std::vector<uint8_t>(in.begin()+at,in.begin()+at+value_len)); at+=value_len;
    }
    if (at!=in.size()) return false;
    out=std::move(result); return true;
}
}
