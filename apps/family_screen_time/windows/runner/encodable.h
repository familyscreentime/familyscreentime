// Reading the arguments of method calls from Dart.
#ifndef RUNNER_ENCODABLE_H_
#define RUNNER_ENCODABLE_H_

#include <flutter/encodable_value.h>

#include <cstdint>
#include <string>
#include <vector>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

inline const EncodableValue* Field(const EncodableValue* args,
                                   const char* key) {
  if (!args) return nullptr;
  const auto* map = std::get_if<EncodableMap>(args);
  if (!map) return nullptr;
  auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

inline std::string StringField(const EncodableValue* args, const char* key) {
  const auto* value = Field(args, key);
  if (!value) return std::string();
  const auto* s = std::get_if<std::string>(value);
  return s ? *s : std::string();
}

inline bool BoolField(const EncodableValue* args, const char* key,
                      bool fallback = false) {
  const auto* value = Field(args, key);
  if (!value) return fallback;
  const auto* b = std::get_if<bool>(value);
  return b ? *b : fallback;
}

inline int64_t IntField(const EncodableValue* args, const char* key,
                        int64_t fallback = 0) {
  const auto* value = Field(args, key);
  if (!value) return fallback;
  if (const auto* i = std::get_if<int32_t>(value)) return *i;
  if (const auto* l = std::get_if<int64_t>(value)) return *l;
  return fallback;
}

inline bool HasField(const EncodableValue* args, const char* key) {
  const auto* value = Field(args, key);
  return value && !value->IsNull();
}

inline std::vector<std::string> StringsField(const EncodableValue* args,
                                             const char* key) {
  std::vector<std::string> out;
  const auto* value = Field(args, key);
  if (!value) return out;
  const auto* list = std::get_if<EncodableList>(value);
  if (!list) return out;
  for (const auto& item : *list) {
    if (const auto* s = std::get_if<std::string>(&item)) out.push_back(*s);
  }
  return out;
}

#endif  // RUNNER_ENCODABLE_H_
