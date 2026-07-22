# Windows build (cross-compile with mingw, or run natively on Windows via MSYS2/mingw)
WIN_CXX = x86_64-w64-mingw32-g++
WIN_TARGET = klock.exe
WIN_SRC = klock_win.cpp

WIN_RELEASE_FLAGS = -O3 -march=x86-64-v2 -flto -ffunction-sections -fdata-sections \
                     -fno-exceptions -fno-rtti -fno-stack-protector \
                     -mwindows -s -DNDEBUG

WIN_LDFLAGS = -Wl,--gc-sections -Wl,--strip-all -static \
              -luser32 -ladvapi32 -lgdi32 -lshell32

# macOS build (native only, needs clang++ / Xcode command line tools)
MAC_CXX = clang++
MAC_TARGET = klock
MAC_SRC = klock_mac.mm

MAC_RELEASE_FLAGS = -O3 -std=c++17 -fobjc-arc -DNDEBUG
MAC_FRAMEWORKS = -framework Cocoa -framework ApplicationServices -framework ServiceManagement

APP_BUNDLE = Klock.app
PLIST = Info.plist
ICON_GEN = gen_icon.mm
ICONSET = Klock.iconset
ICNS = Klock.icns

.PHONY: release release-mac icon bundle clean

release:
	$(WIN_CXX) $(WIN_RELEASE_FLAGS) $(WIN_SRC) -o $(WIN_TARGET) $(WIN_LDFLAGS)

release-mac:
	$(MAC_CXX) $(MAC_RELEASE_FLAGS) $(MAC_SRC) -o $(MAC_TARGET) $(MAC_FRAMEWORKS)

icon:
	$(MAC_CXX) -std=c++17 -fobjc-arc -framework Cocoa -o gen_icon $(ICON_GEN)
	./gen_icon $(ICONSET)
	iconutil -c icns $(ICONSET) -o $(ICNS)
	rm -rf $(ICONSET) gen_icon

bundle: release-mac icon
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(MAC_TARGET) $(APP_BUNDLE)/Contents/MacOS/$(MAC_TARGET)
	cp $(PLIST) $(APP_BUNDLE)/Contents/Info.plist
	cp $(ICNS) $(APP_BUNDLE)/Contents/Resources/$(ICNS)
	@echo "Built $(APP_BUNDLE) — drag it to /Applications, then open it once."

clean:
	rm -rf $(WIN_TARGET) $(MAC_TARGET) $(APP_BUNDLE) $(ICONSET) $(ICNS) gen_icon
