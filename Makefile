PROJECT = VoxNote.xcodeproj
SCHEME = VoxNote
CONFIG = Debug
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData/VoxNote-hffbexvpilrkvzhfwwelmarvtoxo
APP = $(DERIVED_DATA)/Build/Products/$(CONFIG)/VoxNote.app

.PHONY: build run clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS,arch=arm64' build

run: build
	open $(APP)

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
