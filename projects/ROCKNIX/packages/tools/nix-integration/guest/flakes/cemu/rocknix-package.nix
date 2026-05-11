{ lib
, stdenv
, fetchFromGitHub
, cmake
, ninja
, pkg-config
, binutils
, nasm
, wayland-scanner
, SDL2_classic
, boost
, curl
, fmt_11
, glm
, glslang
, gtk3
, hidapi
, libpng
, libusb1
, libwebp
, libzip
, openssl
, pugixml
, rapidjson
, libsodium
, spirv-tools
, vulkan-headers
, vulkan-loader
, wayland
, wxwidgets_3_3
, zarchive
, bluez
}:

let
  manifest = import ./rocknix-package-manifest.nix;
in

# Direct ROCKNIX cemu-sa package replica for Layer 14 guest testing.
#
# This intentionally does NOT inherit from nixpkgs#cemu. The point of this
# candidate is to remove nixpkgs' Cemu wrapper/fixup/package-shape from the
# experiment and express the ROCKNIX package.mk contract directly in Nix.
stdenv.mkDerivation rec {
  pname = manifest.pname;
  version = manifest.version;

  src = fetchFromGitHub {
    inherit (manifest.source) owner repo rev hash fetchSubmodules;
  };

  patches = map (patch: patch.file) manifest.patches;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    binutils
    nasm
    wayland-scanner
    wxwidgets_3_3
  ];

  buildInputs = [
    SDL2_classic
    boost
    curl
    fmt_11
    glm
    glslang
    gtk3
    hidapi
    libpng
    libusb1
    libwebp
    libzip
    openssl
    pugixml
    rapidjson
    libsodium
    spirv-tools
    vulkan-headers
    vulkan-loader
    wayland
    wxwidgets_3_3
    zarchive
    bluez
  ];

  strictDeps = true;

  cmakeFlags = manifest.cmakeFlags ++ [
    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
    # Characterization gate: ROCKNIX host /usr/bin/cemu fingerprints as an
    # ELF EXEC binary while nixpkgs-derived candidates used PIE/DYN wrappers.
    "-DCMAKE_EXE_LINKER_FLAGS=-no-pie"
  ];

  env = {
    NIX_CFLAGS_COMPILE = "-Wno-changes-meaning -fpch-preprocess";
    NIX_LDFLAGS = "-no-pie";
  };

  preConfigure = ''
    # ROCKNIX cemu-sa/package.mk pre_configure_target hooks.
    sed -e '/find_package(cubeb)/d' -i CMakeLists.txt
    sed -e 's#glm::glm#glm#' -i src/Common/CMakeLists.txt src/input/CMakeLists.txt

    # fetchFromGitHub does not preserve .git, while ROCKNIX's package fetcher
    # gives CMake enough git metadata to report `Cemu 6f6c129`. Preserve that
    # user-visible host parity explicitly instead of accepting Cemu's 0.0
    # fallback.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'add_definitions(-DEMULATOR_HASH=''${GIT_HASH})' \
        'add_definitions(-DEMULATOR_HASH=${manifest.source.shortRev})'

    # Keep the bundled imgui submodule. nixpkgs#cemu replaces imgui with a
    # packaged copy, but this direct candidate is intentionally source-faithful.
    # ROCKNIX's aarch64 patch adds -mcmodel=large for imgui. That is hostile to
    # Nix's PIC default; IPO is disabled, so dropping the flag keeps the build
    # linkable without reintroducing nixpkgs' imgui replacement.
    substituteInPlace src/imgui/CMakeLists.txt \
      --replace-fail "target_compile_options(imguiImpl PRIVATE -mcmodel=large)" \
        "# -mcmodel=large incompatible with Nix PIC default; dropped" || true
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/Cemu" "$out/nix-support/rocknix-cemu-build"

    cemuBinary=""
    for candidate in ../bin/Cemu_* bin/Cemu_*; do
      if [ -f "$candidate" ]; then
        cemuBinary="$candidate"
        break
      fi
    done
    if [ -z "$cemuBinary" ]; then
      echo "error: Cemu binary not found in build output" >&2
      find . .. -maxdepth 3 -type f -name 'Cemu_*' -print >&2 || true
      exit 1
    fi

    install -Dm755 "$cemuBinary" "$out/bin/Cemu"
    cat > "$out/bin/cemu" <<EOF
#!${stdenv.shell}
set -eu

cemu_wrapper_dir=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
vulkan_loader_lib_path="${lib.makeLibraryPath [ vulkan-loader ]}"

if [ -n "\$vulkan_loader_lib_path" ]; then
  export LD_LIBRARY_PATH="\$vulkan_loader_lib_path''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
fi

# Cemu's Linux screensaver-inhibit path has crashed in SDL compatibility
# stacks during ROM startup. The package entry point keeps this generic runtime
# guard with the emulator instead of requiring ROCKNIX launcher glue.
export SDL_VIDEO_ALLOW_SCREENSAVER="''${SDL_VIDEO_ALLOW_SCREENSAVER:-1}"
export SDL_HINT_VIDEO_ALLOW_SCREENSAVER="''${SDL_HINT_VIDEO_ALLOW_SCREENSAVER:-1}"

exec "\$cemu_wrapper_dir/Cemu" "\$@"
EOF
    chmod 755 "$out/bin/cemu"

    mkdir -p "$out/share/Cemu/config/SM8550"
    cp ${./settings.SM8550.xml} "$out/share/Cemu/config/SM8550/settings.xml"

    for dataDirName in gameProfiles resources; do
      dataDir=""
      for candidate in \
        "../bin/$dataDirName" \
        "bin/$dataDirName" \
        "$NIX_BUILD_TOP/$sourceRoot/bin/$dataDirName"; do
        if [ -d "$candidate" ]; then
          dataDir="$candidate"
          break
        fi
      done
      if [ -z "$dataDir" ]; then
        dataDir=$(find "$NIX_BUILD_TOP" -path "*/bin/$dataDirName" -type d -print -quit 2>/dev/null || true)
      fi
      if [ -z "$dataDir" ]; then
        echo "error: Cemu runtime data directory not found: $dataDirName" >&2
        exit 1
      fi
      cp -r "$dataDir" "$out/share/Cemu/"
    done

    test -d "$out/share/Cemu/gameProfiles/default" || {
      echo "error: Cemu default gameProfiles runtime data missing from direct ROCKNIX Cemu output" >&2
      exit 1
    }
    find "$out/share/Cemu/gameProfiles/default" -type f -name '*.ini' -print -quit | grep -q . || {
      echo "error: Cemu default gameProfiles runtime data contains no profiles" >&2
      exit 1
    }
    test -f "$out/share/Cemu/resources/sharedFonts/CafeCn.ttf" || {
      echo "error: CafeCn.ttf shared font missing from direct ROCKNIX Cemu output" >&2
      exit 1
    }
    test -f "$out/share/Cemu/config/SM8550/settings.xml" || {
      echo "error: SM8550 default settings.xml missing from direct ROCKNIX Cemu output" >&2
      exit 1
    }

    mkdir -p "$out/nix-support/rocknix-cemu-build"
    ${binutils}/bin/readelf -h "$out/bin/Cemu" > "$out/nix-support/rocknix-cemu-build/readelf-header.txt"
    ${binutils}/bin/readelf -d "$out/bin/Cemu" > "$out/nix-support/rocknix-cemu-build/readelf-dynamic.txt"
    if grep -q 'libcubeb' "$out/nix-support/rocknix-cemu-build/readelf-dynamic.txt"; then
      echo "error: direct ROCKNIX Cemu unexpectedly links dynamic libcubeb" >&2
      exit 1
    fi
    {
      grep -H 'cubeb' CMakeCache.txt build.ninja 2>/dev/null || true
      find . -maxdepth 5 -path '*cubeb*' -print 2>/dev/null || true
    } > "$out/nix-support/rocknix-cemu-build/cubeb-evidence.txt"
    grep -q 'dependencies/cubeb\|cubeb' "$out/nix-support/rocknix-cemu-build/cubeb-evidence.txt" || {
      echo "error: bundled Cubeb build evidence not found" >&2
      exit 1
    }

    # Build evidence for post-build fingerprinting. These files are small and
    # text-oriented; live validation should read them before interpreting FPS.
    {
      printf '%s\n' 'pname=${manifest.pname}'
      printf '%s\n' 'version=${manifest.version}'
      printf '%s\n' 'source-rev=${manifest.source.rev}'
      printf '%s\n' 'source-short-rev=${manifest.source.shortRev}'
      printf '%s\n' 'fetch-submodules=true'
      printf '%s\n' 'patches=${lib.concatMapStringsSep " " (patch: patch.name) manifest.patches}'
      printf '%s\n' 'expected-runtime-data=${lib.concatStringsSep " " manifest.runtimeData}'
      printf '%s\n' 'default-settings=share/Cemu/config/SM8550/settings.xml'
      printf '%s\n' 'package-entry-point=bin/cemu'
      printf '%s\n' 'real-binary=bin/Cemu'
      printf '%s\n' 'wrapper-vulkan-loader=true'
      printf '%s\n' 'bundled-cubeb=true'
      printf '%s\n' 'no-dynamic-cubeb=true'
      printf '%s\n' 'vulkan-loader-lib-path=${lib.makeLibraryPath [ vulkan-loader ]}'
    } > "$out/nix-support/rocknix-cemu-build/manifest.txt"

    if [ -f CMakeCache.txt ]; then
      cp CMakeCache.txt "$out/nix-support/rocknix-cemu-build/CMakeCache.txt"
    fi
    if [ -f compile_commands.json ]; then
      cp compile_commands.json "$out/nix-support/rocknix-cemu-build/compile_commands.json"
    fi
    printf '%s\n' '${lib.makeLibraryPath [ vulkan-loader ]}' > "$out/nix-support/rocknix-cemu-build/vulkan-loader-lib-path"
    if [ -f build.ninja ]; then
      awk '/Cemu.*:.*CXX_EXECUTABLE_LINKER/ || /build .*Cemu_/ { print }' build.ninja \
        > "$out/nix-support/rocknix-cemu-build/link-lines.txt" || true
    fi
    ${stdenv.cc.targetPrefix}c++ --version > "$out/nix-support/rocknix-cemu-build/compiler-version.txt" 2>&1 || true
    env | sort | grep -E '^(NIX_|CMAKE|CC=|CXX=)' > "$out/nix-support/rocknix-cemu-build/build-env.txt" || true

    runHook postInstall
  '';

  # Keep PIC enabled for shared/object-library components; test executable
  # non-PIE posture through CMAKE_EXE_LINKER_FLAGS/NIX_LDFLAGS.
  hardeningDisable = [ "fortify" ];

  passthru = {
    rocknixPackageManifest = manifest;
  };

  meta = {
    description = "Direct ROCKNIX cemu-sa package replica for Layer 14 guest testing";
    homepage = "https://github.com/cemu-project/Cemu";
    license = lib.licenses.mpl20;
    mainProgram = "cemu";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
