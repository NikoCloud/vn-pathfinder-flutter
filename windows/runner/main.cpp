#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

#pragma comment(lib, "shell32.lib")

// ── Crash log (#22) ─────────────────────────────────────────────────────────
// Native crashes (in the Flutter engine, a plugin or a Windows dialog) never
// reach Dart's error hooks, so the launcher records them itself:
//   • logs\native-crash.txt: exception code, the module it happened in and
//     the offset inside it, enough to find the source line with symbols.
//   • logs\running-<pid>: written at start, removed after a normal exit. One
//     left behind by a process that's gone means that run ended badly; it's
//     renamed to logs\unclean-<pid> for the app to report on its next start.
// Everything is written with plain Win32 calls into buffers prepared at
// start, so the crash handler itself doesn't allocate.

namespace {

wchar_t g_logs_dir[MAX_PATH] = {0};
wchar_t g_crash_file[MAX_PATH] = {0};
wchar_t g_marker_file[MAX_PATH] = {0};

// %APPDATA% first, the folder the app's Dart side uses, so both always agree
// (including when APPDATA points somewhere else); Windows' known folder if
// it's unset.
bool PrepareLogsDir() {
  std::wstring dir;
  wchar_t env[MAX_PATH];
  const DWORD n = ::GetEnvironmentVariableW(L"APPDATA", env, MAX_PATH);
  if (n > 0 && n < MAX_PATH) {
    dir = env;
  } else {
    PWSTR appdata = nullptr;
    if (FAILED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &appdata))) {
      return false;
    }
    dir = appdata;
    ::CoTaskMemFree(appdata);
  }
  dir += L"\\VN Pathfinder";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  dir += L"\\logs";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  if (dir.size() + 40 >= MAX_PATH) return false;
  wcscpy_s(g_logs_dir, dir.c_str());
  swprintf_s(g_crash_file, L"%s\\native-crash.txt", g_logs_dir);
  swprintf_s(g_marker_file, L"%s\\running-%lu", g_logs_dir, ::GetCurrentProcessId());
  return true;
}

void WriteAll(HANDLE file, const char* text) {
  DWORD written = 0;
  ::WriteFile(file, text, static_cast<DWORD>(strlen(text)), &written, nullptr);
}

LONG WINAPI OnCrash(EXCEPTION_POINTERS* info) {
  if (g_crash_file[0] == 0 || info == nullptr || info->ExceptionRecord == nullptr) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  HANDLE file = ::CreateFileW(g_crash_file, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return EXCEPTION_CONTINUE_SEARCH;

  const EXCEPTION_RECORD* rec = info->ExceptionRecord;
  void* address = rec->ExceptionAddress;

  // Which module the crash happened in, and where inside it.
  char module_name[MAX_PATH] = "unknown";
  unsigned long long offset = reinterpret_cast<unsigned long long>(address);
  HMODULE module = nullptr;
  if (::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(address), &module) &&
      module != nullptr) {
    char path[MAX_PATH] = {0};
    if (::GetModuleFileNameA(module, path, MAX_PATH) > 0) {
      const char* base = strrchr(path, '\\');
      strcpy_s(module_name, base ? base + 1 : path);
    }
    offset -= reinterpret_cast<unsigned long long>(module);
  }

  SYSTEMTIME now;
  ::GetSystemTime(&now);
  char line[512];
  sprintf_s(line,
            "time: %04u-%02u-%02uT%02u:%02u:%02uZ\r\n"
            "exception: 0x%08lX\r\n"
            "module: %s\r\n"
            "offset: 0x%llX\r\n",
            now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
            static_cast<unsigned long>(rec->ExceptionCode), module_name, offset);
  WriteAll(file, line);
  if (rec->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && rec->NumberParameters >= 2) {
    sprintf_s(line, "access: %s 0x%llX\r\n",
              rec->ExceptionInformation[0] == 0   ? "read"
              : rec->ExceptionInformation[0] == 1 ? "write"
                                                  : "execute",
              static_cast<unsigned long long>(rec->ExceptionInformation[1]));
    WriteAll(file, line);
  }
  ::CloseHandle(file);
  // Let Windows Error Reporting carry on as usual.
  return EXCEPTION_CONTINUE_SEARCH;
}

bool ProcessIsRunning(DWORD pid) {
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return false;
  DWORD code = 0;
  const bool running = ::GetExitCodeProcess(process, &code) && code == STILL_ACTIVE;
  ::CloseHandle(process);
  return running;
}

// Markers whose process is gone become unclean-<pid>; another copy of the app
// that's still open keeps its marker.
void FlagEndedRuns() {
  std::wstring pattern = std::wstring(g_logs_dir) + L"\\running-*";
  WIN32_FIND_DATAW found;
  HANDLE search = ::FindFirstFileW(pattern.c_str(), &found);
  if (search == INVALID_HANDLE_VALUE) return;
  do {
    const DWORD pid = wcstoul(found.cFileName + 8, nullptr, 10);
    if (pid == 0 || ProcessIsRunning(pid)) continue;
    std::wstring from = std::wstring(g_logs_dir) + L"\\" + found.cFileName;
    std::wstring to = std::wstring(g_logs_dir) + L"\\unclean-" + (found.cFileName + 8);
    ::MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_REPLACE_EXISTING);
  } while (::FindNextFileW(search, &found));
  ::FindClose(search);
}

void WriteMarker() {
  HANDLE file = ::CreateFileW(g_marker_file, GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  SYSTEMTIME now;
  ::GetSystemTime(&now);
  char line[64];
  sprintf_s(line, "%04u-%02u-%02uT%02u:%02u:%02uZ\r\n", now.wYear, now.wMonth, now.wDay,
            now.wHour, now.wMinute, now.wSecond);
  WriteAll(file, line);
  ::CloseHandle(file);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  const bool logs = PrepareLogsDir();
  if (logs) {
    FlagEndedRuns();
    WriteMarker();
    ::SetUnhandledExceptionFilter(OnCrash);
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"vn_pathfinder", origin, size)) {
    if (logs) ::DeleteFileW(g_marker_file);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  // A normal exit: this run doesn't need reporting.
  if (logs) ::DeleteFileW(g_marker_file);
  return EXIT_SUCCESS;
}
