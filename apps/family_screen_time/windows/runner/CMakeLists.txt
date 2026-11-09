target_sources(${BINARY_NAME} PRIVATE
  "monitor.cpp"
  "app_info.cpp"
  "notice_windows.cpp"
  "platform_channel.cpp"
)

target_link_libraries(${BINARY_NAME} PRIVATE
  Wtsapi32
  Powrprof
  Shell32
  Ole32
  Mmdevapi
  Shlwapi
  Version
  Windowscodecs
)